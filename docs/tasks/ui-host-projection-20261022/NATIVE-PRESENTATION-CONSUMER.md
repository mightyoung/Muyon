# Actual presentation consumer checkpoint / partial Host implementation

## Source and ownership

Branch task/ui-host-projection-20261022. Identity/batch checkpoint:
86fc3fe7193a14d99ce72d107f07a1add7794552. Ordinary dependency merge:
a2314cec535261e7ceec3d1133e7828f04f678ea imports EXACT B
662aeec6d6462cabfcc317e855ae23797dd88d51; no merge into main/develop.
Native crates and generated file have NO diff against that B input.
Actual generated01e1c019501c30a4c2c9ff532b2e82035f3e2442 file SHA256:
c71b8062e07da7ee07059557acba768a7193b680fb20bc193a359b919d7dacdb.
The reported upstream23/814 tests remain B evidence at its exact input, not our
fresh execution, new Kotlin/Service acceptance, source-invalidation or device proof.
Read Shell c0c2dc994df099c36c83813adf8410dac999d943 real Activity contract; no
MainActivity/ChatScreen/ui/documents edits or invented visibility/principal port.

## Actual source implementation (internal protocol v0; NOT ready Shell IPC)

ProductChatRuntime.withReaderScope(session,project,generation,callback) derives a
revocable snapshot from its sole original ScopeRegistry. Immediate release is an
irreversible reader-session fence, including getters already queued before cleanup.
4096 tombstones maximum; saturation closes reader admission instead of evicting
revocation. Reader projections do not authorize document reads or assert account ACL.

ProductService.withReaderPrincipal(actualBinder,project,generation,callback) joins
actual registered same-UID Binder/session, Runtime snapshot and real native health
workspace/epoch/synthetic=false. Liveness rechecks membership/scope/stopped. No model
or Messenger JSON route supplies principal/visible/allow. The two private factories
newReaderAdmission(principal) and newReaderPresentationTransport(principal) use ONE
ReaderDocumentBatchDomain for this actual Service/native owner across all clients.
These private factories are construction seams, not a usable IPC contract for Shell.

ReaderAdmissionRegistry.runNativeDocumentBatch(originalPrincipal,originalLease,
operation(permit),drain(permit),clearExact,clearAll,discardExact) serializes pre-call
admission, actual native operation, drain even on error, tail identity check and
result admission. No B can open between A business call and its unwatermarked drain.
A/B/ABA old callback invokes ZERO native/drain/clear callbacks. Invalidations remain
caller-routed; unknown/lost drain globally poisons. CLEAN tail identity loss clears
EXACT original selection under lock, then discards result. Publication AFTER async
render still requires fresh Activity + original native frame checks; this primitive
alone is not render admission. Thread, shared domain, exact source and original
selection bind the temporary ReaderNativeBatchPermit. No serialized/stored permit,
no cross-thread or later batch reuse. Scope loss refuses more business calls while
keeping original administrative drain admitted; callback result is withheld.

NativeReaderPresentationPort uses ACTUAL generated ProductCore calls and records:
beginSelection, open(DocumentPresentationOpenRequest/DocumentAccessRequest),
chunk(DocumentPresentationUseRequest)->DocumentPresentationChunkResult, check,
advanceFrame, closeExact and administrative takeInvalidations. Scope is freshly
constructed from Service-derived principal for every call. Exact immutable source
maps canonical Scope/DocumentRef including unsigned revision STRING; no latest ID,
frame arithmetic, fake grant or mutable request reuse. open also requires source to
match the original selection in the permit. Existing grant ID/generation and native
selection token must be ORIGINAL facts from real policy/native responses. There is
currently NO production resolver supplying them and NO attached reader route.
Check does not renew or issue; explicit advance delegates to actual native. Native
bytes/projections are raw internal transport, never PFD/renderer/safety/editing proof.

## Tests and independent review

Test-first missing permit API compiler RED retained reader-native-permit-red.log.
Earlier release/tail regressions RED and independent initial proofs are retained.
Commands (actual Kotlin2.2.20, JVM17, -Werror):

```bash
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/run-admission.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/host-projection-tools/json.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/run-offline.sh
bash apps/muyon_android/gradlew --offline :app:compileDebugKotlin
```

First two exit0/PASS: evidence/reader-native-permit-final.log and
reader-native-runtime-regression.log. Admission runner compiles only the pure
principal/registry plus tests, NOT Android Service or NativeReaderPresentationPort.
It covers A/B ordering, no late A clear of B, unknown drain, exact source/domain,
off-thread/escaped permit refusal and mid-operation scope loss with drain/clear/
discard once. All native/visibility callbacks in these tests are SYNTHETIC fixtures.
Runtime regression compiles actual Runtime, derives real scope projections and proves
release race closed, while exercising no native/transport calls.

Independent reviewer statically checked all seven generated methods/types and exact
DocumentRef mapping, actual generated SHA; no new Important in bounded source review.
Its executed independent final admission log is retained separately. No adapter
Android compilation claimed. git diff --check passes.

Android command exit2: NOT_RUN existing Gradle8.13 executable unavailable;
evidence/reader-native-android-check.log. No stubs, SDK/dependency/cache/network or
permission workaround. THIS environment also lacks cargo/rustc; B native execution
is not represented as local execution. No real user files/model/search/external send.

## Pending, not denied: precise remaining owners/contracts

1. Native current policy/root grant mapping: LOCAL-WORKSPACE-READER-POLICY-REQUEST.md
requests exact existing grant observation, live root from already valid authority,
transactional readonly continuation/new <=30s grant + audit/revocation fences, exact
original outcome/stop. No initial universal workspace document consent inferred.
The product policy for FIRST grant absent existing permission remains explicit.
2. Real authorized catalog: exact canonical refs/source digests/listing generation
with current scope/policy; no title/URI/research-cache identities or fake empty store.
3. Join actual Activity surface to real Service/Binder epoch and registered scope;
accept genuine selection synchronously, preserve opaque native token before lookup.
Shell c0c2 supplied real Activity adapter but host=null; private factories here are
NOT a final bound client. Do not guess an IPC or activate a JSON principal route.
4. Exact native invalidation decoding/routing and deadline-aware controller, actual
read-only bounded seekable PFD/render/cache disposal, original resource cleanup on
owner revocation/shutdown independent of stale callbacks. This batch guarantees
drain but does NOT implement full lifecycle administrative cleanup.
5. Real Service/native/PFD and Android acceptance including >30s, background, page/
selection change, revoke/generation/source changes and stale response cleanup are
NOT_RUN. Native EOF ready is not PDF parse/render proof. verified=false remains.

No main/develop edits, force push, deletion, deployment, payment, credentials,
permission expansion, real request, historic unknown retry/ledger mutation. This is
an implemented, reviewable transport/identity batch; overall Reader/UI is incomplete.
