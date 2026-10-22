# Concrete native policy port request / real Host identity implementation

This continues eb853; missing Activity adapter is NOT an overall development stop.
Runtime/Service identity producer and shared pre-call/batch admission are now code,
with real existing identity sources. Native policy/issuance remains a separate owner
contract, no fake allow or inferred grant. Product reader is not enabled.

## Actual existing mechanisms reused

ProductService validates same OS UID before registering Binder->session. Its actual
ProductCore.open(root,workspace,epoch,false) validates/open owns BusinessStore; health
returns actual workspace/epoch/synthetic=false. New private withReaderPrincipal
uses these facts + Runtime.withReaderScope's real selected session/project/generation.
Revocable ReaderScopeSnapshot is an atomic READONLY projection of sole ScopeRegistry,
not a second scope authority. It invalidates on scope change, immediate release plus
queued cleanup, and Runtime close. Its liveness remains false across an old epoch.
Principal liveness rechecks actual clients membership and snapshot; no JSON inputs
can supply principal/allow/account. Private callback remains on Runtime control queue.

LocalWorkspaceReaderPrincipal is only transport/local scope identity, NEVER account
ACL or document permission. It deliberately does not assert project still exists:
native ReadScope::current checks store.project(project)?.deleted in transaction.
That current-scope check also is NOT document permission (existing registry comment
explicitly says project selection itself grants no disclosure/write right).

Existing document_grants records exact document+grant/gen/owner_epoch/operations/
expiry/active, but no current surface/principal/root-reading-intent assignment.
Core document_grant rejects expired permission; issue_document_grant_trusted can
set active=1 for a new generation and demands authentic policy. Therefore do NOT
call it after a cached old permission/unlocked boolean to revive revoked state.

## Precise request to core/FFI policy owner

Use existing same BusinessStore owner/transaction. Do not expose arbitrary workspace,
owner_epoch, caller allow/permission JSON, account or model principal. Host provides
its actual private Service scope and trusted Activity original selection; native
derives actual store identity and validates current live project and exact source.
The following are semantic requests, not guessed/generated ABI calls:

1. **Readonly exact policy/grant observation** for trusted scope + exact canonical
   DocumentRef + already server-resolved grant reference + required ReadText/Render.
   No enumeration/latest-grant scan and no issuance/idle renewal. Return genuine
   exact metadata/source digest, current persisted grant generation/active/revoked/
   expiry/readonly operations, native epoch/policy version. It must distinguish
   expiry from explicit revocation/generation replacement; unknown/missing/corrupt
   stays unavailable. A snapshot is evidence, not an allow token or future permission.
2. **Begin continuation policy session** only while the exact already-issued grant
   is currently valid for required readonly operation and actual visible selection
   is fresh. Atomically bind a NEW local reading intent to original document/source,
   scope/principal domain, actual initial grant, readonly subset, policy version and
   revocation fence. No adopt-by-latest/digest, no retroactive root from expired grant.
   This implements continuation of EXISTING read authority, not a new policy that all
   workspace documents are universally readable.
3. **Reauthorize exact continuation** with original attempt, root policy session,
   expected current grant generation, actual fresh single-use Activity selection
   proof/version and readonly operation. In ONE native transaction recheck current
   project/head/source, nonrevoked/nonpoisoned root/policy, readonly subset and
   liveness fence; issue a NEW <=30s grant generation plus audit/outcome. Do not
   lengthen old generation, add writes, revive active=0, or accept stale selection.
   Root grant expiry alone cannot mint authority; current continuation policy must
   positively pass. Revoke policy root and grant chain atomically, before late issue.
4. **Exact original outcome/stop**: unknown never replays. A terminal/root fence
   cannot be dropped by expiry/capacity/compaction. Audit/issue/terminal failure is
   fail-closed, with retained exact original and bounded capacity. See eb853 for
   explicit state/clock/retention acceptance. No UI/model-accessible issuer route.

Root-grant observation may reuse canonical transaction-owned helpers; extract the
owner-controlled mutation hook if needed, never nest the existing internally-
transactional issuer or duplicate grant SQL in Kotlin/FFI. Policy-only probes must
not open bytes or return unrelated document contents merely to validate a project.

## One concrete product policy decision still NOT inferred

Does explicit visible selection of ANY registered document in this local workspace/
project authorize its FIRST ReadText/Render grant if no prior document authorization
exists? Existing ReadScope/project ownership alone does not state that document
policy, and raw/presentation FFI5488 explicitly has no issuer/selection->grant join.
This broader initial-access rule is NOT implemented or silently assumed. Parent/
policy owner must pin the intended rule and actual trusted source of the first grant.
The new continuation path above is narrower: root starts from genuine existing read
permission and exact fresh reading intent. Unknown initial policy stays unavailable.
This decision does not block independent identity/admission/native transport work.

## Host batch/selection code and exact integration boundary

ReaderAdmissionRegistry uses one ReaderDocumentBatchDomain per actual Service/core
owner shared across clients. It refuses stale scope/selection BEFORE callback,
handles A1->B2->A3 by object/sequence identity, and old stop cannot close current B.
Replacing a surface makes old registry terminal. A dead owner never revives.

runDocumentBatch serializes native operation, drain after success AND errors,
current identity/selection check, exact result discard and output invalidation.
clear_all has no watermark, so another client/surface cannot open B between A's
operation and A's drain. Lost/failed drain globally poisons/invalidates; ordinary
stale local callback executes ZERO operation/drain/clear. Unknown cleanup is not
success. Generic callbacks are internal integration seams, NOT fake production
native/policy implementations; no grants/PFDs are fabricated by this primitive.

Read5488ec69 PRESENTATION-FFI-INTERFACE/HANDOFF and actual generated01e1c019501c30a4c2c9ff532b2e82035f3e2442
handoff on662aeec6: native begin_selection must run synchronously at the ACTUAL
trusted selection event before async lookup; retain its real opaque token, not
this Host sequence as native selection_id. Its one-use open token/actual frame
are additional native fences. Do not call begin from a delayed callback.

Actual native frame/check/PFD publication still needs original pid/frame, request-
start anchored deadline, <=check_after_ms poll and fresh Activity recheck. Registry
is pre-admission, not a renderer or native grant authority. True global invalidation
is conservative; old callback denial is not an instruction to clear a new frame.

## Verification and remaining integration

Test-first missing-source/API failures retained at reader-admission-red.log and
reader-runtime-scope-red.log. Actual Kotlin run-admission covers pre-call zero-call
A/B/ABA, forged lease/owner/gen, terminal/no revive, cross-client serialized operation
and drain, stale A no B clear, unknown drain poison and operation-error drain. Its
liveness and native callbacks are SYNTHETIC fixtures, not policy/native/device proof.
Actual Runtime run-offline tests derive real selected ScopeRegistry snapshots,
then invalidate on switch/release/null scope without native/transport calls.
Service source itself still cannot be Android-compiled in this environment.

Production withReaderPrincipal/newReaderAdmission are private typed producer/factory
seams, not registered Messenger/model operations. No fake policy adapter is attached.
Shell real visible/selection adapter and native atomic policy port must connect at
these exact seams after their fixed contracts; Android/actual grant/>30s tests stay
NOT_RUN and verified=false. Actual presentation binding is available; it is no
longer described as ungenerated. Its real native transport is the next independent
Host consumer slice; root-policy absence cannot be used to fabricate grant fields.

## Independent review / failure preservation

Reviewer independently reproduced two Important defects in the initial slice:
queued Runtime scope could revive after release, and CLEAN batch tail identity loss
discarded new bytes without clearing prior output. Both source regressions were RED
(reader-scope-release-race-red.log, reader-tail-clear-red.log) before the fixes.
Release now retains irreversible bounded session tombstones (4096; saturation closes
all reader admission), and snapshot liveness checks that fence. CLEAN tail identity
loss clears EXACT original selection under shared batch lock before result discard.
Independent original proofs and fixed reruns are retained in evidence/*independent.log;
fixed queued_snapshot_live_after_release=false; old_output_visible=false, clears=1,
discarded=1. Both complete Kotlin runners independently exit0. These are offline
synthetic sequencing checks, not native/Activity/device/policy or >30s evidence.

Read Shell c0c2dc994df099c36c83813adf8410dac999d943 READER-ACTIVITY-SURFACE.md:
its real Activity surface exists but host=null/catalog absent; this slice does NOT
claim it attached to Service. Exact typed private identity factory is
withReaderPrincipal(actualBinder,project,generation,callback), followed by
newReaderAdmission(principal), shared Service domain. These are internal seams,
not a working IPC/API for shell to guess. Catalog, root grant mapping/policy,
PFD resource transport, actual binding consumer and typed surface IPC remain pending.
Actual presentation binding01e1 is available and is the next integration dependency.
