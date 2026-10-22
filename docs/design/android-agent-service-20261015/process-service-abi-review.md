# B Service ABI and execution-plan independent review

2026-10-15. Reviewer: original non-author host/UI reviewer. Read-only scoped review; no product, test, workflow, generated binding or repository edits. No tests/builds/device runs. This supplements process-service-contract-review.md; it does not replace earlier findings or claim runtime acceptance.

## Fixed inputs

| Input | SHA256 |
| --- | --- |
| ANDROID-AGENT-SERVICE-SLICE.md | `5be6a11739f3d48153c18631ebbe9473bff7e2aa9adb7f44cc5a3ca5f8c58e18` |
| B-SERVICE-ABI.md | `b361f966ff15f92de762b47fbcfada2619bcfe086e2d7aa9bafd5aa1cd63aea4` |
| B-SERVICE-IMPLEMENTATION-PLAN.md | `66d96b9140e51939d26e4c7bad9d1fb7235b355adf19eea3237b21fd81ff8e76` |
| B-SERVICE-CHECKS-PLAN.md | `33fbabfbc85b1f7d9f799882e385fdf6b23e2dfe498fa564302b6222fbbdf284` |
| B-SERVICE-CHECKS-PREFLIGHT.md | `66ae205ffff9beb03725b1f142b902a7ff55c87538889575bc7f42676287528b` |

Source reference is fixed `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`. Earlier ABI references in author plans are historical; activation must bind final b361 and the root's immutable docs commit.

## ABI verdict

**SPEC PASS / QUALITY C0. Critical0 / Important0 / Minor0 open in the reviewed ABI.** No additional permission or architecture decision is needed for the selected B design. The user's design-then-development authorization applies; no A prerequisite is introduced.

**ABI-I1 Important — CLOSED.** The initial ABI required a durable run identity for every terminal while start could be volatile. Cancel/quota/mkdir/index-validation failures before durable admission could not be represented honestly. b361 introduces the closed SettledNoAdmission record with immutable intent and reason, containing no run/task/attempt/receipt identity. Publication requires affirmative no-admission/no-handler evidence and actual cleanup/join. Partial or ambiguous index publication instead remains Unresolved/Unknown, with optional genuine identity. This does not interpret missing evidence as NotStarted and does not synthesize an admitted Cancelled terminal.

**Exactness clarifications — CLOSED.** StartReply uses the actual AgentRunSnapshot type and only the outer reply supplies authoritative metadata. InvalidRoot and safe setup/root-lock/restore failure mappings are specified without paths or exception strings. Completed requires the real paired State task/attempt, original durable binding, actual RecordedSuccess receipt identity and reasonNone; cancellation cannot erase a recorded raw success. Closed/Closing reconnect obtains only bounded read-only reconciliation leases and cannot reopen execution.

The concrete signatures preserve the lifecycle contract: client_gone and await_settled are Service-only FFI, not UI/AIDL operations. Constructor/bootstrap and the sole settlement waiter stay off Binder/main and admission locks. Rust publishes both normal Terminal and Closed only after actual worker drop/join and durable classification; Kotlin schedules the wait without deciding business outcome. RootLease survives normal settlement and is released only during true closed settlement. Before an actual controller exists, local TransportInitializing invents no Rust epoch, revision, lease or Ready. Final spec's bootstrap generation invalidation and late-controller close/drain remain binding even where not repeated in the ABI.

The Send/Sync shell contains only control/snapshot/lease data; non-Send native session/provider/handler state remains worker-local. All four variants use the existing Agent drive and registered read/authority/purpose/raw-receipt/final-byte chain. Persistent in-process Catalog is explicitly selected inside the independent whole-Agent Service; existing Linux child remains a regression backend. No additional child sandbox or Android runtime proof is claimed.

## Execution-plan finding

**PLAN-I1 Important — OPEN at plan hash66d96b9, narrowly administrative and independently verifiable.** The new host tests necessarily add nonempty Rust test groups. Fixed source `rust-agent-host-lab/checks/full.py:33–46` validates exact groups and total; `test_full.py:20` fixes host total25. The checker's preflight correctly identifies the required inventory update, but the implementation-plan ownership table grants the checker only bridge/checks and the bridge workflow. Without an explicit root carve-out, either the required legacy full gate will reject the new groups or an author must cross ownership.

Resolution: authorize the original checker for `experiments/redesign/rust-agent-host-lab/checks/cases.json` and `checks/test_full.py`. Preserve all25 native_read names and family; add separate source-frozen service groups, exact totals and negative controls. Do not relax unknown-group, missing/renamed/skipped-test or exit-code rejection. No full.py parser or legacy workflow change is presently needed. A full.sh build-identity adjustment is conditional on the actual host identity mechanism and should receive a separate exact carve-out only if needed. This is not a new user approval gate or a reason to change the B design.

Otherwise the plan is executable: independent Rust and actual generated-JVM semantic RED precede native GREEN; initial refusing-controller reach is not called Agent-dispatch reach. UI state TDD may proceed independently, but fake ports do not prove Rust or Binder. The original owners retain their directories, generated code is produced from the actual library, source/feature/library/binding identities are separate, and required inverse classifications preserve INVALID/SURVIVED rather than manufacturing KILLED. Fixed final combination CI and non-author review precede integration.

## Evidence limits

This review ran only reads/hash/source inspection. **0 new tests, 0 builds, 0 Android executions.** Future test names/counts, compiled RED/GREEN, generated API24 Object compatibility, real Binder/PID/UID/lifecycle, filesystem locks/fsync and process-death reconciliation remain unproved until their respective gates run. Android runtime is explicitly NOT_RUN and is not inferred from Linux/JVM, a manifest or APK assembly. The existing contract review's official-source rationale remains applicable; no new platform claim is introduced here.

## Final plan closure — 90890896

Independently re-read the amended ownership and fixed-input clauses. Final B-SERVICE-IMPLEMENTATION-PLAN.md SHA256 is `90890896eee06dfab03efdb05a0a5c3a1062d6916e6519ed9e3fa515e4420c77`. It binds spec5be6 and ABI b361 explicitly and supersedes historical 3c5 author-note references.

**PLAN-I1 — CLOSED.** The original checker now has the explicit two-file host inventory carve-out, limited to source-frozen new service/transport families while preserving native_read25 and all existing regression families. No parser/native inverse runner changes are authorized without evidence; any needed full.sh identity change returns to root for a precise ownership decision. The implementation and strict mandatory gate can now advance without crossing author boundaries or weakening old expectations.

**Final combined design/ABI/plan verdict: SPEC PASS / QUALITY C0; Critical0 / Important0 / Minor0 open.** Recommend root publish the immutable docs base and activate the original native/UI/checker owners for the specified TDD sequence. No generic permission question remains. This is design/execution-plan readiness, not implementation or Android runtime acceptance. No source changed and no tests/builds ran during this closure.
