# Paused implementation checkpoint / exact handoff

User explicitly requested a transparency checkpoint and pause of further expansion. No source changes are made after the reviewed freeze. Work is retained; overall task is not cancelled. This report is NOT a completion or qualification approval.

## Immutable source / remote publication

- Prior base:98dadd88beeec552bff6efbef5325efbeeae04c3.
- IPC/snapshot slice:9df65972629e99bde08547a2fd0758d73a3138bd, already pushed/read back.
- Concrete Linux source freeze:f90c977825369e3dc2a78ff6503ce5596a14f268.
- This final checkpoint seal changes docs/evidence only; its complete pushed SHA is returned by execution response after remote verification.

Scope: tools/document_fidelity/adapters/runner/linux has concrete IPC/snapshot/kernel/backend/session/provider/host-stage/bootstrap/worker-permit/seccomp/layout implementations plus tests. Existing Authority adds same-lock consume/release; launcher reconciles reserve-owned children even before logical spawn; worker_gate and3 narrow workers add inherited-FD permit and engine-entry notification. No Rust/Android/production UI/main/develop changes. Native provider source exists with all HostOSBackend methods implemented, but its native path has never run here and has known review gaps. Do not integrate/execute this source as qualified production backend.

## Actual commands/results; nothing running or pending now

- `python3 -m unittest discover -s tools/document_fidelity/adapters/runner/linux/tests -v`: author26 tests PASS exit0; evidence/linux-frozen.log. Initial slice test had6 tests at its exact checkpoint, later expanded.
- `python3 -m unittest discover -s tools/document_fidelity/adapters/runner/tests -v`: author28 PASS exit0; evidence/runner-frozen.log.
- `python3 -m unittest discover -s tools/document_fidelity/tests -v`: author60 PASS exit0; evidence/legacy-frozen.log.
- Independent reviewer exported exact f90 snapshot `/tmp/linux-review-independent`, ran all3 suites:26/28/60 PASS exit0. Verbatim logs copied into evidence/independent/.
- stdlib AST parse29 adapter files PASS; LinuxBackend.__abstractmethods__ empty. This is syntax/source logic evidence, not a native execution claim.
- Real socketpair framing/partial I/O/EOF/timeout/SCM credentials/unsolicited FD tests ran as expressly authorized. Syscall/process/domain/snapshot tests use fakes/mocks; no real Popen/worker/kernel qualification/namespace/engine execution.
- Original8 binary fixtures and3 manifests unchanged; hashes in evidence/CHECKPOINT-ENVIRONMENT.json. Original /workspace/Muyon remains untouched.
- No tool/dependency/permission blocker for source editing/unit tests; no command or reviewer still running. The remaining issues are source defects/qualification gaps, not an opaque inProgress operation.

## Independent verdict: NOT APPROVED; confirmed P2 remains unfixed

**Stable identity feature absence is not checked before Popen.** kernel.py qualification does not precheck `os.pidfd_open` / `signal.pidfd_send_signal`. Native launch creates gated trusted host-stage before first pidfd_open; when that API is unavailable/ENOSYS, reconciliation calls the same unavailable API and returns false. Pure fake probe outputs:

`Popen(fake) → pidfd_open(fake ENOSYS) → pidfd_open(fake ENOSYS)`; `reconcile=False`, `process_created=True`, `pidfd=None`.

Raw source and output: evidence/independent/linux-review-independent-capability-probe.py and .log. The probe replaces Popen, socketpair, channels, fstat, pidfd and process status with fakes. No actual process was created. Initial reviewer message suggested P1; its final report classifies this as P2. Parent should use final P2 while retaining original evidence.

Impact: insufficient stable identity can create a trusted gated supervisor instead of HOLD before any process. The isolate gate is not released on this path, so this is not evidence of a namespace/engine launch or authorization bypass. It enters outcome_unknown/quarantine and cannot claim completed reap. On continuation, implement prelaunch Linux/Python capability and allowed kernel-feature qualification, TDD missing/ENOSYS/FD-exec cases, then final fixed-SHA independent recheck before runtime admission. No repair is performed after the user's pause request.

**Further observations requiring confirmation:** only image has actual ST_RDONLY observation. bwrap and host mapped-library paths are hash/mode checked but may be owner-writable; readonly host-source requirement needs explicit kernel evidence or equivalent pinned immutable source. bwrap maps are not independently observed after host-stage exec (the existing launch maps check is pre-exec Python stage). FD-exec availability is checked inside host_stage after creation, likewise should move before launch. No native exploit/runtime path was validated. These are accurately pending, not declared fixed or dismissed.

Reviewer confirmed existing paths for pre-spawn reconciliation, same-lock original Authority consume/release, logs to dual EOF before exit, reaped-only snapshot and fake-to-Native qualification rejection. Passing tests do not override the findings above.

## Real qualification still absent; allowed continuation

Current config/scope records, read-only approved runtime/host-loader bundle and concrete license/provenance/isolation approval, predelegated empty cgroup2 limits/private≤32MiB tmpfs/dedicated unprivileged NNP subreaper are not configured. Native startup, bwrap argument compatibility, actual proc evidence/UID mapping/seccomp/inherited FD/whole-tree reap/snapshot/real engine-entry paths remain NOT_RUN. Provider defaults HOLD. No resource/security configuration has been created or weakened.

Historical actual bwrap namespace setup for harmless /usr/bin/true failed UID-map with `Read-only file system`, exit1. Known filesystem denial, not approval-review rejection. It was not retried, substituted, relocated or escalated. Original evidence remains ../engine-evaluation/evidence/isolation-attempt.log.

After parent resolves the checkpoint, resume existing plan: fix confirmed prelaunch capability HOLD and verify readonly-source observations with fake syscall RED/GREEN, recheck immutable final source independently, then hand off exact resource/artifact/authority/native-test prerequisites. Keep current actual engine/sandbox prohibition. No need to redo pushed primitive slice or completed external actions. Four-format Office/native safety/edit/render/recalc/CAS integration remains incomplete; Leader B alone merges develop. Historical2 unknown requests/¥0.002620 untouched.
