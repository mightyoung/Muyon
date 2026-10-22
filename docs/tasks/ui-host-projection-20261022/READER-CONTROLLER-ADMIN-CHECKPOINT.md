# Host controller/admin implementation checkpoint

Source parent660f03da29d26d6cdcf28c594c959cc6c43098e4. Exact Shellc0c2dc994df099c36c83813adf8410dac999d943
merged asacb0fa2110e4117c9e0fe0e62b15161e75f27e8c. No handwritten MainActivity,
ChatScreen or UI component changes. Merge's two conflicts initially chose exact
Shell files. Its cold fixture still used obsolete scalar prepare signature; actual
runner failed. Restore EXACT B662aeec6d6462cabfcc317e855ae23797dd88d51
HostPersistenceProjectionChecks.kt (only import/prepare signature differ, no assertion
changes), then rerun PASS. Original RED remains reader-controller-shell-regression.log.
Native crates/generated have NO diff against B662; existing7-method actual native
transport remains separate from the NOT-YET-generated seven policy APIs.

## Implemented source

ReaderPresentationDeadline anchors native valid_for_ms/check_after_ms to actual
request-start monotonic clock. Absolute display expiry is returned EARLIEST native
TTL, not a fixed30s. Renew due2s before that deadline (immediately for short grants),
check due<=native interval<=1000ms. Check results never extend original frame deadline;
only a genuine replacement ticket starts another deadline.

ReaderContinuationController consumes ACTUAL Shell ReaderSurfaceRequest and
ReaderVisibilityObservation types, not a second physical/lifecycle model. It checks
current original object/scope on timers and late responses; checks static pages and
requests continuation before actual earliest deadline without a new selection.
Independent hard-expiry plus1s in-flight watchdog close/suspend output and retained-
owner stop on hung check/sample/renew. It preserves original unknown IDs even after
expiration; never auto-replays. Different challenge cannot reuse an observation;
sampling must occur after its request, <=2s old, original object, bounded one-use
challenge/observation IDs. Duplicate reply wrappers for current genuine pid/frame
cannot close current output. Root stop can match same selection/lifecycle across page
sequence, while old A selection cannot stop new B. clearExact/disposeLate/publish and
administrative stop remain exact required callbacks; actual owned PFD ledger needed.

ProductService private newReaderContinuationController provides its REAL Handler/
elapsedRealtime clock, exact source field checks and sole original Runtime scope.
Backend=null is deliberate failclosed: admit returns false, NO successful native or
rendered frame is manufactured. This private factory is NOT an installed Activity
host, public Messenger ABI or cross-process join. Actual callbacks must reach existing
Activity owner/fence before publish. Genuine challenge sampler is requested precisely
in READER-CONTROLLER-SHELL-REQUEST.md; current Shell lacks that periodic callback.

ReaderAdministrativeOwner/Permit and runAdministrativeBatch are separate from live
principal/business permit. They retain original native identity and owner session,
allow exact cleanup even after scope/background/poison, always drain success/error,
with unknown/lost drain conservatively global. Old A ordinary failure+CLEAN drain
does not stop B; owner/domain/thread/lifetime prevent adoption or replay. No operation
opens/rebinds a new core. The broad disconnected-client release additionally checks
ACTUAL original client UUID absent from Service clients; page/scope changes cannot
call it while that client is still live. NativeReaderPresentationPort uses actual
generated exact close/admin drain and documentReadReleaseOwner methods. Scope loss
cannot force it through withReaderPrincipal. Service core close uses same domain->
Service lock order. Do NOT call administration inside @Synchronized releaseClient:
actual later release scheduling must happen after that monitor is released.

Administrative methods are implemented, but no root/resource ledger, release event
caller, policy-stop/reconcile adapter or global Android-output router is claimed.
Controller's stopOriginalAdministrative must bind actual original root/owner; callback
absence is not fake success. Backend calls MUST be nonblocking on controller queue:
synchronous FFI needs a separate bounded native worker, otherwise Handler watchdog
cannot run. This real worker/actual adapter is still pending fixed generated APIs.

## Approval update and precise policy request

FIRST-READ-APPROVED.md records parent-delivered user approval09:23:33UTC. New genuine
selection may establish this exact source-known registered current-project readonly
intent without another confirmation. Missing implementation is NOT new user approval.
Explicit persistent doc read deny/version must survive grant IDs/revisions/epochs;
lifecycle stop cleans owned initial/child grants but is NOT permanent file denial or
shared-parent revocation. Additive initial native admission and before-root original
stop/reconcile/one-use event requirements are fixed there. Native/backend still absent,
not a policy approval gate flip. Independent static doc review no new Important.

## Actual checks / retained failures

```bash
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/run-admission.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/host-projection-tools/json.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/run-offline.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/host-projection-tools/json.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-reader-surface-checks.sh
bash apps/muyon_android/gradlew --offline :app:compileDebugKotlin
```

First4 exit0/PASS: reader-controller-final.log, reader-controller-runtime-regression.log,
reader-controller-shell-compatible-green.log, reader-controller-surface-regression.log.
All pure checks use real Kotlin2.2.20 -Werror/JVM17; Runtime/shell JSON uses actual
org.json jar, no Android/generated stubs. Fake native/clock/sample fixtures are ONLY
tests. Latest fake-clock static-page sequence reaches39s/two handoffs then hung
renewal times out at40s; this is NOT a real >30s device/native/continuous-render proof.

Admin/deadline missing API test-first RED retained reader-continuation-admin-red.log.
Controller actual challenge replay and duplicate current-frame wrapper RED retained
reader-controller-red.log / reader-controller-duplicate-red.log. Independent reviewer
found two additional Important defects: different challenge reused one observation;
expired late Unknown lost ID. Its original executed proof retained in
reader-controller-gaps-independent.log; fixed independent proof accepted1 instead of2,
original ID retained. Full independent runner PASS; reviewed source hashes retained
reader-controller-source-final2-independent.sha256. No new Important in bounded final
review. Earlier GREEN logs predate later regression cases; final log is authoritative.

Android command DIRECT tool exit2: existing Gradle8.13 absent,
reader-controller-android.log = NOT_RUN. Service/NativePort and actual Handler/Activity
classes are NOT compiled by pure runner. No SDK/stub/security/cache workaround or
native execution claimed. Production/backend/PFD/IPC/policy integration and real
Android >30s/lifecycle/source/grant revoke/no-flash acceptance remain NOT_RUN.

No main/develop modification, forcepush, branch deletion, deployment/payment,
credential/permission expansion, real model/search request, historic unknown retry
or fee-ledger mutation. Existing verified=false remains; Reader backend=null and
Activity host=null remain unavailable. This is source/controller/scheduler/admin
checkpoint, not whole Reader/UI completion.

Final independent rerun after expanded39s fake-clock case: evidence/reader-controller-admin-final3-independent.log
exit0/PASS. Four reviewed source hashes match final2 unchanged. Cold fixture blob
exact B662 =3dda27458f59003a6b6e49038f91cb6c0898c236; c0 difference only import/prepare
signature, no assertion changes. All five current production source hashes are in
reader-controller-final-source.sha256. FIRST-READ-APPROVED.md independently statically
reviewed with no new Important; original review log/hash retained. No native policy
endpoint behavior or device verification was executed for that approved policy.
