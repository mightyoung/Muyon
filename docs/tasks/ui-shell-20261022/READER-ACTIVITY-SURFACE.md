# Real Activity surface and exact-selection adapter slice

Based on fixed shellf04f4ef237a386b250deb903b9373229febd62ce; no cold decoder/request
logic changed. Read fixed Host contracteb853296278cca3ec2eed7985ca64272e17e2544,
READER-REAUTHORIZATION-CONTRACT.md. Also read presentation combination662aeec6d6462cabfcc317e855ae23797dd88d51
BINDING-HOST-HANDOFF.md and generated binding reference01e1c019501c30a4c2c9ff532b2e82035f3e2442.
Those are upstream contract/native facts, not fresh shell native/Android verification.
No merge of that Host/B combination and no Service/Runtime/binding/reader component edits.

## Actual production construction and event sources

MainActivity constructs ActivityReaderSurface.attach(this), not a fake lifecycle provider.
The adapter privately samples the actual ComponentActivity Lifecycle, decor attachment,
window visibility/focus, finishing/destroyed and multiwindow/PiP state on the main Looper.
A real LifecycleEventObserver registers start/resume/pause/stop/destroy. MainActivity
also fences pause/stop before super, forwards window focus/mode callbacks, and the
adapter registers/removes the actual decor attach listener. Callback inputs cannot
come from card/model JSON. The adapter uses main Handler to serialize late Host replies.

Workspace comes only from actual health data already used by MainActivity; project
comes from its actual project SharedPreferences, observed for changes. Workspace health
is descriptive scope, NOT a principal/policy consent. Binder loss, workspace/project
switch and actual background/window events invalidate the local intent. No Service
session/epoch is read through reflection or replaced with a fabricated scope handle.

The existing documents destination now mounts ReaderSelectionSurface. Exact route token
fences its DisposableEffect; actual navigation stops it immediately before tab change,
not only after delayed Compose disposal. Old route disposal cannot close a new route.
Actual new Activity/rotation creates a fresh surface UUID, never restores live visibility,
selection consent, grant or principal from rememberSaveable/preferences. A tab may be
restored but has no selected/admitted reading intent. Foreground return does not resume
old intent; a new genuine selection is needed.

## Exact selection and pre-Host fence

ReaderExactSelection contains the exact ReaderDocumentRef + immutable source identity
and SHA256. ReaderDocumentChoices captures that typed row in its actual Compose onClick,
and Activity.chooseFromUserGesture calls local select/dispatch on the owning thread.
No editable model/card JSON, URI/path, title lookup, latest revision fallback, visible,
principal or current field can populate this selection/permission path.

Every genuine selection increments selection sequence, even A -> B -> identical A;
separate frame sequence keeps the same document intent on page change. Local request
generation and lifecycle epoch invalidate queued work on route/scope/lifecycle changes.
Before private Host invocation, dispatch checks the exact original request object,
route, selection and generation, then resamples the actual Activity/window. Old A after
accepted local B is rejected with zero Host.open calls. An additional Host/native
serialized pre-call fence remains REQUIRED: discarding output cannot undo destructive
native open after an IPC reorder. This local proof does not claim that native race solved.

The typed private adapter contract has distinct acceptSelection/open/closeFrameExact/
stopReadingExact hooks. Selection acceptance is called synchronously at the genuine
selection, before async lookup/open; a frame does not accept another selection or revoke
its reading chain. Terminal stop addresses original selection event/chain, not an
unrelated current frame. Host must serialize these events with its actual owner slot,
principal, opaque native selection token and scope BEFORE native open/issue. The names
are a shell-owned semantic port, not a newly claimed Messenger/native ABI.

ReaderVisibilityObservation records exact local request + fresh owning-thread monotonic
sample + one-dispatch observationId. It is NOT the Host/native original reauthorization
attempt, a grant, permit, validity deadline or native freshness attestation. A native
coordinator must supply its genuine original-attempt-bound sampling/admission contract;
this slice does not guess its ABI, clock bridge or turn the proposed2s bound into policy.
Unsupported overlay semantics remain unresolved, and multiwindow/PiP is refused. Focus
and decor sampling do not establish physical unobscured visibility; all real authority
remains disabled until current policy/device semantics are reviewed and supplied.

## Local resource handling

All Host replies are posted to the Activity owner before state changes. Stale replies
close only their exact one-shot ReaderSurfaceResource, never close-current. Repeated
same resource replies are idempotent, including duplicate callbacks from another thread.
A wrong request result first captures/stops its original in-flight selection. Closing
an old resource unsuccessfully immediately suppresses current output, stops the current
owned chain and holds further admission; it does not leave a displayed frame active.
Unknown close retains its resource identity and does not blindly retry underlying close,
auto-reopen or silently clear hold on new route. Native cleanup/reconciliation still
belongs to Host; UI cannot prove OS-wide destruction of already-read bytes.

## Explicit current unavailable result and exact Host requests

Production Activity adapter has host=null and no real catalog source. It displays
catalog-unavailable, NOT an empty-store claim; there are no invented selectable rows.
Thus **real canonical-document selection and authorized open cannot yet be exercised**.
The actual Activity/route path exists, while the selection handler is ready for exact
host records and is covered by synthetic metadata tests. This is not a running reader,
a mock-as-real Host, or >30s continuous-reading delivery.

Pending, not denied: original Host owner must provide all of the following in its files:

1. Actual private bound document catalog/client source: exact shared-store DocumentRef,
   immutable source identity/digest, current workspace/project and correlated listing
   version. Preserve unsigned decimal document revision and format; no paper/title/URI
   identity invention. Wire those records into the Activity choices without auto-select.
2. Genuine Binder-owner/Service-epoch/reader-scope registration for this actual Activity
   surface object plus current policy-issued principal and explicit readonly consent.
   UI health.workspace/project is not that join. Never accept caller JSON allow/visible/
   current/principal or a high caller sequence as evidence.
3. Concrete acceptSelection route under the serialized Host/native owner admission:
   call actual documentPresentationBeginSelection only for this current authentic event,
   retain opaque token/scope, and reject stale local seq/lifecycle BEFORE destructive
   presentation open. Do not call begin on a late callback. Map local frame sequence to
   actual native frame generations; they are distinct domains, not interchangeable IDs.
4. Actual typed PFD/lease result and exact owned stop/frame-close callbacks, native
   invalidation drain and cleanup outcome. One wrapper per exact owned resource; never
   recycle a current B resource as A's late reply. Ready bytes are not PDF render proof.
5. Dedicated native original-attempt reauthorization/sampling/clock-deadline/revocation/
   audit/retention protocol from policy owner. UI can sample its actual surface on its
   thread, but cannot invent original attempts/principal/deadline authority. Real >30s
   renewal and uncertain original lookup require that reviewed port; no timer in this
   slice issues, rotates or extends anything.

ProductService/ProductChatRuntime/new document client/host files remain original owner's
scope. New generated presentation binding and its reported23FFI/814workspace results
alone do not supply these Activity/principal/PFD/policy checks. verified is not opened.

## Actual checks and retained limits

```bash
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-reader-surface-checks.sh
```

Actual compiler2.2.20, -Werror JVM17, real reader Models + local fence/checks. Exit0/PASS;
reader-surface-final-green.log. Covers exact A/B/A, scope, route stale dispose, separate
frame/no re-accept, accept-before-open, stopped original selection rather than page,
zero Host.open for stale tickets, fresh sample even a missing physical callback,
foreground no auto-resume, owner-thread rejection, delayed/duplicate replies, old FD
close once, queued wrong-thread duplicate not closing active FD, stale-close failure
suppressing current output/hold, foreign request cleanup, unavailable/multiwindow and
uncertain cleanup hold. Synthetic Host/resources are explicitly test-only, not a native
or policy integration proof.

Initial stub behavior RED reader-surface-red.log retained. Early reader-surface-green.log
predates four static review findings. Reviewer found duplicate/wrong-thread/cleanup/
foreign ownership issues; subsequent code and new regression cases fixed them. These
review fixes are NOT claimed as an independently executed RED/GREEN for every defect.
Independent final input hashes/actual rerun: READER-SURFACE-REVIEW.md and
reader-surface-independent.log. No outstanding Important in that bounded review.

Cold/request regression command remains run-host-shell-checks.sh with existing KOTLINC
and actual JSON_JAR;3 runners PASS exit0, reader-surface-cold-regression.log. Cold source,
ChatScreen, Runtime/Service and reader component directories unchanged fromf04.
Actual Android compile/test/device command used existing Gradle8.13 offline:

```bash
GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache \
MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle \
./gradlew --offline --no-daemon --console=plain :app:compileDebugKotlin \
 :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest
```

Exit1 before product compilation, AGP8.11.1 unresolved; reader-surface-android.log.
Actual Activity/Handler/Lifecycle observer, window behavior, instrumentation target
ReaderActivityLifecycleTest, PDF/PFD/native/foreground/>30s/IME/TalkBack tests remain
NOT_RUN. No Android stubs, SDK install retry, network/security/permission workaround,
credential, paid CI/dependency, model/search request, historical unknown/fee action or
main/develop modification. Whole reading and overall UI acceptance remain incomplete.

Existing package checks also executed: python3 -m unittest discover -s
apps/muyon_android/checks -p 'test_*.py',17 PASS exit0; reader-surface-package-checks.log.
These are package/evidence gates, not Android lifecycle acceptance.
