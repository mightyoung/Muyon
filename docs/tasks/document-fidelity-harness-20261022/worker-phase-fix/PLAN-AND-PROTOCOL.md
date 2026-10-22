# Worker phase / terminal TTL / execution observation correction

Base7fb2c8ef82b30ee6572119016c8bb906733c129d. Scope remains adapter/runner and independent docs. No real engine/worker CLI/namespace tests or third-party imports. Actual isolation rejection is not retried or bypassed.

## Planned slices and actual TDD

- Worker lifecycle: fake callbacks during terminate/kill/reap/reconcile/cleanup/quarantine try mint and consume, with fresh or preissued worker permits. red.log reproduces old window; window-green.log proves denied, including successful exit/reap path and candidate validator normal behavior.
- Admission TTL: distinct ttl-red.log records final verify_terminal callback advancing10→20 with admission expiry15 and operation deadline50; old code reports success. ttl-green.log proves candidate/credential withheld after callback. This is an invalid success report correction, not an observed authorization bypass: consume_credential already rejected expired credentials.
- Execution accounting: execution-red.log records fake nonzero worker exit still labeled engine executed; execution-green.log corrects it. Spawn is only worker_process_started; engine execution requires separately authenticated HostExecutionEvidence. Raw JSON booleans, missing/wrong request/engine proof stay HOLD.
- Freeze source, fresh independent review, final evidence and task-branch push/readback. Full SHA and review outcome recorded in REPORT.md after completion.

## Source state machine correction

Authority admission and worker authority are different phases. `close_worker_stage(lease)` is irreversible/idempotent under Authority RLock, flips worker_closed and revokes every preissued worker capability. New worker mint checks worker_closed; consumption also checks its live parent record, so a delayed permit cannot survive closure. Ready cannot reopen a closed worker phase. The admission lease remains available for independent validation and terminal host verification; it is not itself a worker-launch permission.

Controller closes worker stage as soon as cancellation/error is observed, before stop/reconciliation callbacks. On normal/nonzero process exit it closes before reap_tree, including descendant checks. `drain` also closes before TERM/KILL. Closure occurs before snapshot, terminal proof, cleanup or quarantine. Existing final finish still closes all admission authority and revokes nonretained validator capabilities. This separates stopping execution from accepting a reaped immutable candidate.

`issue_credential` rereads the registered trusted backend's current monotonic time after `verify_terminal` returns and checks lease binding/expiry/open state again, before minting. This handles verifier callback time and reentrant closure; a longer operation deadline cannot extend admission TTL.

## Additive receipt3 / host-session proposal change

Receipt3 adds `worker_process_started` (false before known process handle; true only in host path with known handle). Spawn never sets engine_execution=executed. Host spawn leaves engine_execution=unknown because worker bootstrap/permit rejection can exit before importing an engine. Simulation still reports engine not_run. An uncertain spawn is reconciled conservatively and does not establish engine entry.

New `HostExecutionEvidence(binding, engine, proof_id)` must arrive from trusted host session `verify_execution(binding, engine, terminal_proof, executor)`, which must authenticate an engine-entry observation against actual pinned runtime/worker/artifact and attempt. Base method returns None, which holds validation and withholds candidate/credential. No worker JSON/env/CLI factory exists. An ordinary worker's output_created or process exit0 is not authenticated execution evidence. Authority checks exact typed evidence/binding/engine, strict bounded proof ID and lease validity before/after callback. Only then may receipt state engine executed; a validator credential additionally requires this verified execution state and independently authenticated terminal evidence.

This method is a required future integration for existing proposed providers; missing method safely returns None/HOLD. It does not change schema1/2 edit requests or any Rust consumer (none wired). Core must consume the opaque credential with current time and atomically recheck auth/scope/revision/idempotency/cancel before its durable CAS. Object-capability trust remains a service-code boundary, not defense against arbitrary malicious Python in trusted service.

## Accurate remaining gaps / permitted next source work

Current real HostSession provider, kernel HostOSBackend and worker IPC bootstrap remain unimplemented/unqualified. Workers do not yet emit an authenticated cross-process engine-entry observation. A future compliant environment must supply authenticated broker/native evidence, staged-context identity, real pinned origins/license/native/font reviews, no-network/RO mounts/resource limits, process-tree reaping and stable snapshots, then actual engine reopen/roundtrip/render/recalc compatibility. All remain NOT_RUN here; no license/install/EULA/credentials/permission changes are authorized by this slice.

Within current source-only authorization, remaining reasonable work includes typed broker IPC wire contracts and authenticated transport integration seams, serialization validation/negative tests, scoped cancellation/commit contract tests with fake peers, and broader explicitly unsupported format plans/fixtures. Creating working OS sandbox isolation, importing engines, issuing real credentials, or declaring public four-format reading/editing complete is outside what this environment's evidence supports. No alternative sandbox path will be tried to avoid the known bwrap UID-map denial.

All FakeHostOS/FakeHostSession tests explicitly use synthetic trusted-API objects; their temporary in-memory capabilities are not genuine host validation credentials and do not install production bootstrap. Neither old simulation nor plain JSON is upgraded.
