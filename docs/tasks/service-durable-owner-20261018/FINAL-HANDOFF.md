# LeaderB durable owner bounded slice

Root is sole integrator. Base PR91 `4b609602f76996ec69e9f51da8bc4261d6a2d94a`; candidate code/workflow SHA `d28e8d3ed08d2185198284794dd116e3d6eb3290`. Draft PR92: https://github.com/mightyoung/Muyon/pull/92 ; base remains `lab/service-admission-bindings-20261018`. No main/develop merge. The PR86-dependent HOLD remains.

## What this slice delivers

A concrete Kotlin/API26 `DurableServiceHostOwner` implements the existing owner source and feeds the generated callback interface through `ServiceHostBindings.callback`. It uses a separately injected guarded trusted authority, never a hardcoded allow. The dedicated fresh SQLite schema persists complete binding/scope, original request and payload, full CallBudget, exact proof, owner, hold expiry, consumed state and metadata admission. Same-epoch immutable ceilings count consumed plus live holds across connections and reconstruction. Commit rechecks current authority, existence-only credential correlation, exact tuple and full proof, then consumes once with admission metadata. It cannot send or read a secret.

This is the deliberately reduced minimum closed loop, not completion of App/Service production binding. No approved production authority exists; Application and private Service remain unchanged in explicit SyntheticLab mode. No fabricated source/profile/approval was installed merely to make a callback allow. Rust core, generated ABI, UI, Auto/FullAllow and Dart are unchanged. This new SQLite v1 component has no legacy task database compatibility or migration claim.

## Independent review and corrections

DESIGN-REVIEW.md accepted the bounded scope with guard/epoch/schema/time requirements. CODE-REVIEW-bf244606.md identified Important I1 (failed admission could roll back expiry observation and allow clock rollback resurrection) and I2 (same-version schema constraints were not verified). They were fixed by separately persisting clock/expiry maintenance inside the same authority guard and validating exact DDL plus implicit constraint indexes. CODE-REVIEW-d28e8d3e.md accepts both corrections and reports no new Critical/Important issue. The initial review remains intact. Final whole-slice review is recorded separately.

## Evidence interpretation

Selected local environment: `/workspace/Muyon`, Linux cloud environment `ccarenv_b64_Y2NhcmVudl8wZTE3N2FmZWQxMTQ4MTkxOWU4YTc4YWYwMWE4NzRlMw`; no local Gradle/kotlinc/SDK was provisioned. Local Android runtime is NOT_RUN. Root's YAML/bash syntax checks, diff checks and frozen-path comparison are static evidence only. Actual builds and instrumentation run in isolated GitHub Actions ubuntu-24.04 workspace `/home/runner/work/Muyon/Muyon`, fresh x86_64 API26 emulator, new UUID-named synthetic SQLite objects only. See CI-BOUNDARY.md and immutable run evidence for commands, SHAs and exact results.

The initial implementation's 11-test pass does not refute the independent defects; the added regression tests and corrected immutable source control acceptance. Tests-first missing-implementation compile RED is a compile failure, not a behavior failure. The later regression run's expiry result and malformed-fixture setup result must be described separately. None of these results establish a real Rust prepare→Kotlin durable ledger→transport path.

## Remaining gates and risks

ConfiguredChat is still unavailable. Required next work: approved actual source/profile/destination/model/capability/policy/grant/quota authority; real existence-only handle owner; Application/Service lifecycle selection and shutdown; real Rust prepare/final_admit integration with this component; secure handle identity/rotation/use; and a transport enforcing the approved full-call limits, cancellation, usage/settlement and recovery. Real provider networking, models, billing and paid services were NOT_RUN.

Payloads, requests, bindings and proofs persist as sensitive local plaintext indefinitely; no encryption, retention policy, pruning or backups. Expired rows remain duplicate/replay tombstones. The supported authority deployment is one process, same authority object per DB; concurrent independent authorities/processes are rejected, not distributed. OS cross-process lease runtime, largest-signed quota and surrogate/all-field matrix, maintenance-transaction storage failure, crash between maintenance/admission commits, power-loss durability, ARM64 and physical devices remain NOT_RUN. Successful persisted clock observations prevent resurrection; unobserved elapsed real time while offline cannot be inferred. Production lifecycle and policy review must resolve these limits before installation.

## Hard boundary retained

I04 old script task.db→HTTP→original-state reopen remains historical platform DENIED_BEFORE_EXECUTION / NOT_RUN (possible cybersecurity risk). No execution, retry, rewrite, split, alternate executor/environment, old-state migration or indirectly containing suite occurred. The final artifact archive download was denied with remote HTTP403 Forbidden; it was stopped without retry or alternate route. The previously obtained full CI log and terminal JSON are retained; the archive copy remains unavailable. Prior failed/cancelled/skipped runs remain preserved. PR86 and dependent combinations remain HOLD; PR90 `060e46f1359915e267f849f3807ec1999b29dd8d` untouched, its eight Dart fixtures not retried. Main/develop unchanged; no force push, deletion, deployment, credentials or real model call.

## Next session

Read this handoff, FINAL-VERIFICATION.md, all independent reviews and CI-BOUNDARY.md. Recheck remote PR86–92 heads, source/CI exact SHAs and writer ownership before any writes. Do not interpret this Draft or synthetic tests as hold release or production approval. The parent later explicitly prioritized actual lifecycle integration; final CI had already started, so the code was kept immutable. NEXT-LIFECYCLE-SLICE.md gives the exact current unreachable path, owned-binding cleanup contract, private storage/authority contracts, and the missing transport-free Rust prepare/final_admit probe. It defines actual Application/private Service and new-schema restart acceptance, rather than another isolated component or a readiness-only completion claim.

## Terminal acceptance

Exact code/workflow d28e8d3ed08d2185198284794dd116e3d6eb3290 passed scoped CI39127896088: required build/JVM/lint plus API26 x86_64 **17/17**. Review defects were fixed and independently accepted. Earlier compile RED39127290205, initial11-test success39127459970, regression RED39127714894 (16 tests, actual expiry bug + separate fixture setup error), and selector SKIPPED outcomes remain intact. Archive download was403 DENIED/not retried; full logs and terminal JSON obtained before it are retained. Details in FINAL-VERIFICATION.md and evidence/.

All workers stopped/released. Root's only remaining writes are this evidence-only handoff/PR status update; source remains immutable. The later lifecycle priority is explicitly carried in NEXT-LIFECYCLE-SLICE.md. The actual App/Service owner integration remains **not delivered** in this source.
